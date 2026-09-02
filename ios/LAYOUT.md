# iOS App Layout

Entry point: `COILApp.swift` (`@main struct COILApp`) configures Firebase and shows
`RootView`, which gates on auth / legal acceptance / onboarding and then hands off to
`MainTabView` — the shipped navigation shell with 4 tabs (Home · My Plan · Progress ·
Profile) plus a floating "+" that presents `AssessmentGatewayView` in a full-screen
cover.

```
ios/PT-Helper/COIL/ (4 files at root)
  COILApp.swift                   # App entry point (@main), Firebase init, scene-phase session handling, AppDelegate
  RootView.swift                  # Navigation root (auth check, legal gate, onboarding gate)
  LoginView.swift                 # Sign-in screen (Google / Apple / anonymous)
  DesignSystem.swift              # Tokens: AppColors, AppSpacing, AppFonts, AppCorners, AppAnimations + reusable components

  Extensions/ (1 file)
    String+Summary.swift          # Truncation / summary helpers for long AI text

  Models/ (22 files)
    UserProfile.swift             # User health profile (Codable)
    PainAssessment.swift          # Per-region pain data + AnalysisResult + ConditionResult
    RehabPlan.swift               # Exercise plan with weekly schedule + RehabExercise
    BodyRegion.swift              # Body map region model + BodySide
    BodyZone.swift                # 6 anatomical zones grouping the 30 body regions
    BodyMapConstants.swift        # 3D model config (colors, scales, proxy geometry)
    InjuryAnalyzer.swift          # Builds AI injury analysis prompts + decodes the response
    WellnessAnalyzer.swift        # Builds AI wellness analysis prompts + decodes the response
    WellnessAnalysisResult.swift  # Wellness analysis output
    WellnessAssessment.swift      # Wellness goal categories + assessment input
    RecoveryInsight.swift         # AI-generated weekly recovery digest
    FormAnalysis.swift            # Exercise form feedback data model (3D joints, rep metrics)
    AdaptiveProgressionAnalyzer.swift  # Pain/adherence trend analysis for plan adjustments
    ProgressionRule.swift         # Progressive-overload rules for difficulty scaling
    WorkoutSession.swift          # Completed workout session data
    Achievement.swift             # Progress milestones and gamification
    AssessmentSnapshot.swift      # Historical assessment comparison
    ConsentPolicy.swift           # Pure decision logic for consent / re-acceptance state
    OutcomeFeedback.swift         # User's after-the-fact rating of analysis accuracy
    SessionEvent.swift            # Session logging events
    Note.swift                    # User observation notes
    LegalContent.swift            # Privacy policy, terms of service (embedded markdown)

  ViewModels/ (14 files)
    InjuryAnalysisViewModel.swift # Pain assessment + two-call AI pipeline
    RehabPlanViewModel.swift      # Plan generation, preferences, verification, Firestore save
    GuidedWorkoutViewModel.swift  # Step-by-step workout with checkpointing + progressive learning
    SavedPlansViewModel.swift     # Real-time Firestore plan listener
    WorkoutViewModel.swift        # Workout session tracking
    WellnessAnalysisViewModel.swift  # Two-call wellness analysis pipeline
    WellnessPlanViewModel.swift   # Wellness exercise + habit plan generation
    RecoveryInsightsViewModel.swift  # Managed Agent recovery insights + caching
    FormAnalysisViewModel.swift   # Pose detection + form feedback orchestration
    ExerciseSwapViewModel.swift   # AI-powered exercise substitution + swap reasons
    ReAssessmentViewModel.swift   # Pain re-assessment snapshots + before/after comparison
    BodyMapViewModel.swift        # 3D body map state management
    OnboardingViewModel.swift     # 6-step profile wizard
    NotesViewModel.swift          # User notes CRUD

  Views/ (67 files total: 44 at this level + Components 16 + OnboardingSteps 6 + Debug 1)
    MainTabView.swift             # 4-tab shell (Home / My Plan / Progress / Profile) + floating '+' + FloatingTabBar
    TabSelection.swift            # Shared TabSelection observable + AssessmentRoute enum
    HomeTab.swift                 # Tab 0: weekly date strip, today's program, preventative tasks
    MyPlanTab.swift               # Tab 1: Injury/Wellness sub-tabs over saved plans
    ProgressTab.swift             # Tab 2: charts, insights, settings, session history
    OnboardingEditView.swift      # Tab 3 / profile edit wrapper around the onboarding steps

    AssessmentGatewayView.swift   # Dual gateway: pain path vs. wellness path
    BodyMap3DView.swift           # RealityKit 3D body map + coach marks
    PainDetailView.swift          # Per-region pain form (collapsible sections)
    PainWizardSteps.swift         # PainDetailView step subviews (wizard extension)
    AssessmentGrowthBackground.swift  # Progress-reactive background for the pain wizard
    AnalyzingView.swift           # AI analysis loading screen + AnalysisDestination routing
    AnalysisResultView.swift      # Results display + rehab-plan preferences sheet
    FullTextDetailView.swift      # Full-text reader for truncated AI prose

    RehabPlanView.swift           # Plan display, edit, swap, guided workout entry
    EditRehabPlanView.swift       # Plan editing sheet (reorder, remove, edit)
    EditExerciseView.swift        # Single-exercise editing
    ExerciseDetailView.swift      # Full exercise detail view
    ExerciseSwapSheet.swift       # Exercise substitution modal

    GuidedWorkoutView.swift       # Exercise execution with resume support
    GuidedWorkoutSummaryView.swift  # Post-workout stats + pain input
    WorkoutSessionView.swift      # Workout session record view

    FormAnalysisView.swift        # Record → pose-detect → AI form feedback flow

    WellnessGoalPickerView.swift  # Wellness goal selection
    WellnessDetailView.swift      # Wellness questionnaire + WellnessDestination routing
    WellnessAnalyzingView.swift   # Wellness analysis loading
    WellnessResultView.swift      # Wellness analysis results
    WellnessPlanView.swift        # Wellness plan display (exercises + habits)

    RecoveryInsightsCardView.swift  # Recovery digest teaser card
    RecoveryInsightsDetailView.swift  # Full recovery insights view
    AdaptiveProgressionBannerView.swift  # Progression recommendation banner

    ReAssessmentPromptView.swift  # Re-assessment prompt banner
    ReAssessmentComparisonView.swift  # Current vs. previous comparison

    AchievementsView.swift        # Achievements display (earned + locked)

    OnboardingView.swift          # Onboarding container (6-step wizard)
    IntroCarouselView.swift       # First-launch intro carousel
    SettingsView.swift            # App settings, account, developer tools
    NotesView.swift               # User notes
    DisclaimerView.swift          # One-time analysis disclaimer
    HealthDataConsentView.swift   # Blocking MHMDA health-data opt-in
    LegalAcceptanceGateView.swift # Launch-time terms/privacy (re-)acceptance gate
    LegalDocumentView.swift       # Privacy policy / terms viewer
    MinorSafetyResourcesView.swift  # Teen-facing safety resources
    ReportConcernView.swift       # User-facing concern report → concernReports collection

    Components/ (16 files)
      ExercisePhaseStepperView.swift  # 3-phase instruction stepper (Start → Move → Return)
      ExerciseImageView.swift     # Exercise image with on-demand generation + SF Symbol fallback
      ExerciseImagePagerView.swift  # Swipeable start/end pose pages for detail views
      ExerciseIllustration.swift  # Exercise illustration wrapper (gradient + difficulty badge)
      ExerciseIconMapper.swift    # SF Symbol mapping for exercise categories
      RegionPainInputView.swift   # Per-region pain slider
      BodyAreaChipPicker.swift    # Chip-cloud body-area picker for onboarding history
      VideoRecorderView.swift     # Video capture for form analysis
      AchievementCelebration.swift  # Celebratory overlay when an achievement is earned
      SeriousWarningModal.swift   # Acknowledgement gate for `.serious` plan findings
      RedFlagAcknowledgementSheet.swift  # Friction gate before a self-guided plan after red flags
      EmergencyRedirectView.swift # Full-screen takeover for `.emergency` findings
      OutcomePromptView.swift     # "How accurate was this?" inline card
      ExpandableSummaryView.swift # Collapsed/expanded long-text summary
      DismissButton.swift         # Isolated @Environment(\.dismiss) leaf (freeze-class workaround)
      ShareSheet.swift            # UIActivityViewController wrapper

    OnboardingSteps/ (6 files)
      BasicInfoStepView.swift     # Name, DOB, sex, height/weight
      MedicalHistoryStepView.swift  # Medical conditions, medications
      SurgicalHistoryStepView.swift  # Surgical history
      InjuryHistoryStepView.swift # Injury history
      ActivityLevelStepView.swift # Activity level selection
      ProfileReviewStepView.swift # Profile review before submit

    Debug/ (1 file)
      MissingImagesDebugView.swift  # DEBUG-only image-diagnostics view (missingExerciseImages)

  Services/ (35 files)
    ClaudeAPIService.swift        # Firebase proxy → Claude API (9 request types)
    APIConfig.swift               # API endpoint configuration
    ResponseValidationPipeline.swift  # Analysis (6-step) + rehab plan (9-step) validation + severities
    BiomechanicalRuleEngine.swift # Deterministic exercise-specific form rules
    FormFeedbackValidationPipeline.swift  # 7-layer form feedback safety validation
    KnowledgeGraphService.swift   # Exercise-condition knowledge graph (v1 + flagged v2 union)
    CrossModelVerificationService.swift  # Cross-model rehab plan verification
    DataQualityScorer.swift       # Pose data quality assessment before AI
    ShadowModeJSONParser.swift    # Shared strict/permissive JSON decode with shadow logging
    TermMatching.swift            # Deterministic, spelling-tolerant clinical term matching
    InputSanitizer.swift          # Prompt-injection stripping + length limits
    PoseDetectionService.swift    # On-device 3D pose detection from video
    PoseAnalysisEngine.swift      # Joint angle, rep, symmetry + alignment analysis
    UserProfileService.swift      # Profile read/write + caching
    ExerciseImageService.swift    # 8-layer fuzzy image matching + Storage download + caching
    BodyModelCache.swift          # 3D body model (USDZ) caching
    ConfiguredBodyModelCache.swift  # Cached fully-configured body-model template for cloning
    AnalysisResultStore.swift     # Persisted analysis results (file-protected)
    FormAnalysisStore.swift       # Per-session form analysis records → users/{uid}/formAnalyses
    OutcomeRecorder.swift         # Outcome ratings → UserDefaults + Firestore
    HistoryRelevanceFilter.swift  # Kinetic-chain health history classification
    ConsentService.swift          # Legal/health-data consent records + UserDefaults mirrors
    RiskAcknowledgementRecorder.swift  # Red-flag risk acknowledgements → Firestore
    SeriousWarningAcknowledgements.swift  # Per-plan `.serious` warning acknowledgement store
    AccountSessionContext.swift   # Account-scoped teardown on sign-out
    PersistenceFailure.swift      # Shared "write didn't reach the server" shape for the UI
    AppStorageKeys.swift          # Single source of truth for shared @AppStorage keys
    SessionLogger.swift           # Navigation, API, error tracking + upload
    AppLogger.swift               # os.Logger categories (API/Images/Data/Auth/Rehab/UI)
    AnalyticsService.swift        # Firebase Analytics events (behavioral only, never PHI)
    NetworkMonitor.swift          # Connectivity status monitoring
    NotificationService.swift     # Local + push notifications, deep links, FCM token
    StreakService.swift           # Workout streak + achievement tracking
    PDFExportService.swift        # Rehab plan PDF export
    TestDataSeeder.swift          # UI test mock data population (launch-argument driven)

  Testing/ (1 file)
    AIStubbing.swift              # DEBUG-only in-process AI fake for UI tests (--uitesting)

  Resources/
    Fonts/                        # Industry-Bold.otf, Inter-{Regular,Medium,SemiBold}.ttf
    body_model.usdz               # 5.3 MB 3D body model for BodyMap3DView
    exercise_image_mapping.json   # Exercise name → image filename mapping
    medical_knowledge_graph.json  # Exercise-condition contraindication graph (v1)
    comorbidity_interactions.json # Medical condition interaction rules

    NOTE: there are NO exercise PNGs in the app bundle. The ~1364 AI-generated
    illustration pairs live in Firebase Storage and are fetched at runtime by
    `ExerciseImageService.downloadFromStorageByFilename`, with the
    `generateExerciseImage` Cloud Function as an on-demand fallback.
    `exercise_image_mapping.json` is a copy synced here from `scripts/output/`
    by `scripts/rebuild_image_mapping.py` — edit it there, not here.

  Assets.xcassets, Preview Content/, COIL.entitlements, PrivacyInfo.xcprivacy

ios/PT-Helper/COILTests/ (103 files)
  TestFixtures.swift              # Shared factory methods for test data (makeProfile/makeAssessment/makePlan…)
  AIRequestTypeContractTests.swift  # Pins the client side of the AI request-type contract
  ResponseSchemaContractTests.swift # Client half of the cross-stack AI response contract
  AccountDeletionOutcomeTests.swift # Only a confirmed HTTP 200 counts as a deleted account
  HomeStripLogicTests.swift       # Home weekly-strip per-day completion logic
  NotificationServiceTimeoutTests.swift  # Sign-out clears the FCM token with a bounded wait
  SessionLogRedactionTests.swift  # Error descriptions must not leak URLs/tokens/emails into logs
  SessionLogUploadDecisionTests.swift  # A session log uploads only for the account that created it

  BodyMap3D/ (1 file — excluded from UnitPlan, run in FullPlan)
    BodyMapCollisionTests.swift   # Tapping 3D body regions selects the correct region

  GroundTruth/ (1 file)
    ValidationRegressionRunner.swift  # Minimum-viable validation regression harness

  Helpers/ (1 file)
    AsyncWaitHelpers.swift        # Await-until-publisher-satisfies-predicate test helpers

  Mocks/ (3 files)
    MockClaudeAPIService.swift    # ClaudeAPIServiceProtocol mock (counts calls, canned responses)
    MockFormAnalysisStore.swift   # FormAnalysisStoreProtocol mock
    MockNotificationCenter.swift  # NotificationScheduling mock

  Models/ (15 files)
    UserProfileTests.swift            # UserProfile defaults + computed properties
    UserProfileFirestoreTests.swift   # UserProfile Firestore encode/decode round trip
    PainAssessmentEnumTests.swift     # PainAssessment enum raw values + cases
    AnalysisResultTests.swift         # AnalysisResult decoding + derived state
    ConditionResultTests.swift        # ConditionResult + match strength
    RehabPlanTests.swift              # RehabPlan structure + weekly schedule
    ProgressionRuleTests.swift        # Progressive-overload week math + guards
    AdaptiveProgressionAnalyzerTests.swift  # Pain/adherence trend → progression verdict
    BodyRegionTests.swift             # BodyRegion catalog invariants
    BodyZoneTests.swift               # Every region zoneKey maps to exactly one zone
    WorkoutSessionTests.swift         # WorkoutSession model + coding
    WellnessAssessmentTests.swift     # Wellness goal enums (snake_case raw values)
    ConsentPolicyTests.swift          # Consent / re-acceptance decision logic
    AgePolicyTests.swift              # Age boundary cases against a fixed reference date
    NoteTests.swift                   # Note model + coding

  Services/ (53 files)
    APIConfigTests.swift              # Model/max_tokens stay server-side only
    ClaudeAPIServiceTests.swift       # Request building + response handling
    ClaudeAPIErrorTests.swift         # ClaudeAPIError cases + descriptions
    ClaudeAPIServiceTelemetryTests.swift  # Every API event carries the required telemetry fields
    ClaudeModelsTests.swift           # Model identifier constants
    ResponseValidationPipelineTests.swift  # Analysis + rehab plan validation steps
    ConditionRetentionPolicyTests.swift    # Condition retention rule (replaced drifting prefix(3))
    DeterministicSafetyGateTests.swift     # End-to-end coverage of the two deterministic safety gates
    ImageAvailabilityValidatorTests.swift  # Step 1 of validateRehabPlan
    RehabPlanGraphVerificationTests.swift  # graphVerification element of validateRehabPlan
    ComorbidityInteractionTests.swift      # Comorbidity interaction map
    BiomechanicalRuleEngineTests.swift     # Exercise-specific form rules
    FormFeedbackValidationPipelineTests.swift  # Form feedback safety validation
    DataQualityScorerTests.swift      # Pose data quality scoring
    PoseAnalysisEngineTests.swift     # Joint angle / rep / symmetry math
    KnowledgeGraphServiceTests.swift  # Knowledge graph lookups against a test graph
    KnowledgeGraphRealDataTests.swift # Same, against the real bundled graph
    KnowledgeGraphExpansionTests.swift  # v2 loader + merge logic behind the feature flag
    KnowledgeGraphCatalogIntegrityTests.swift  # Every graph exercise id exists in the catalog
    CrossModelResponseParsingTests.swift  # parseCrossModelResponse mapping
    CrossModelVerificationRetryTests.swift  # Retry wrapper behavior
    ShadowModeJSONParserTests.swift   # Strict vs. permissive decode + shadow logging
    InputSanitizerTests.swift         # Prompt-injection stripping + length limits
    InputSanitizerFuzzTests.swift     # Known-bypass fuzz corpus
    TermMatchingTests.swift           # Deterministic spelling-tolerant clinical term matching
    RepParsingTests.swift             # RepSpecParser cases
    WeeklyScheduleTests.swift         # Weekly schedule generation
    HistoryRelevanceFilterTests.swift # Kinetic-chain history classification
    InjuryAnalyzerPromptTests.swift   # Analyzer construction + prompt shape
    InjuryAnalyzerBuildMessageTests.swift  # buildUserMessage content
    InjuryAnalyzerVerifyPipelineTests.swift  # Two-call primary+verify pipeline + fallback
    WellnessAnalyzerBuildMessageTests.swift  # Wellness intake → user message
    WellnessAnalyzerVerifyPipelineTests.swift  # Wellness two-call pipeline
    WellnessAnalysisValidatorTests.swift  # Wellness analysis validation
    WellnessPlanValidatorTests.swift  # Wellness per-exercise validation
    ExerciseImageServiceTests.swift   # Image resolution happy paths
    ExerciseImageMappingIntegrityTests.swift  # Catalog invariants on the bundled mapping
    ExerciseImageResolverFuzzyPatchTests.swift  # Regression coverage for resolver fixes
    ExerciseImageResolverReplayTests.swift  # Historical AI exercise-name corpus replay
    ExerciseImageSingularMatchTests.swift  # Singular names the fuzzy matcher used to hijack
    AnalysisResultStoreTests.swift    # Persisted analysis result store
    ConsentServiceTests.swift         # Consent records + UserDefaults mirrors
    SeriousWarningAcknowledgementsTests.swift  # Per-plan serious-warning acknowledgement store
    LocalUserDataResetTests.swift     # Local data reset clears checkpoints + counters
    OutcomeInstrumentationTests.swift # OutcomeRecorder data layer
    StreakServiceTests.swift          # Streak math without Firebase
    StreakServicePainImprovementTests.swift  # "pain_improved" achievement wiring
    NotificationServiceTests.swift    # Scheduling, deep links, permissions
    AnalyticsServiceTests.swift       # Typed analytics events
    AnalyticsHealthDataContractTests.swift  # Analytics must never carry health data
    TelemetryHygieneTests.swift       # Silent-failure guards on the two telemetry paths
    ContrastRegressionTests.swift     # Contrast floors for design-token pairings
    PerformanceTests.swift            # Hot-path performance measurements

  Utilities/ (1 file)
    StringSummaryTests.swift        # String+Summary truncation helpers

  ViewModels/ (19 files)
    InjuryAnalysisViewModelTests.swift  # Analysis orchestration + error states
    RehabPlanViewModelTests.swift       # Plan generation, preferences, save
    GuidedWorkoutViewModelTests.swift   # Set tracking, checkpointing, completion counters
    WorkoutViewModelTests.swift         # Session list ordering + insertion
    WorkoutPersistenceIntegrityTests.swift  # Workout state that failed to reach the server
    SavedPlansViewModelTests.swift      # Listener behavior incl. unauthenticated launch
    SavedPlansRoundTripTests.swift      # rehabPlans Firestore document round trip
    ExerciseSwapViewModelTests.swift    # Swap suggestions + persistent state cleanup
    ReAssessmentViewModelTests.swift    # Snapshot save + before/after comparison
    RecoveryInsightsViewModelTests.swift  # Managed Agent insights + caching
    FormAnalysisViewModelTests.swift    # Pose → feedback orchestration
    BodyMapViewModelTests.swift         # Region selection state
    BodyMapViewModelZoneTests.swift     # Zone drill-down selection
    OnboardingViewModelTests.swift      # Step validation + advancement
    NotesViewModelTests.swift           # Notes CRUD
    WellnessAnalysisViewModelTests.swift  # Wellness analysis orchestration
    WellnessAnalysisViewModelRoutingTests.swift  # Wellness emergency red-flag routing
    WellnessFlowStateTests.swift        # Wellness assessment flow state lifecycle
    WellnessPlanViewModelTests.swift    # Wellness plan generation

  Views/ (1 file)
    RegionPainInputViewTests.swift  # Post-workout region-pain list stays in lockstep with the plan

ios/PT-Helper/COILUITests/ (8 files)
  UITestBase.swift                # Shared launch-argument / consent-dismissal harness
  OnboardingUITests.swift         # Onboarding wizard flow
  AssessmentJourneyUITests.swift  # Body map → pain detail → analysis journey
  GuidedWorkoutUITests.swift      # Guided workout flow (resume, end, set completion)
  MyPlanTabUITests.swift          # My Plan tab navigation
  ShellNavigationUITests.swift    # Tab shell + floating "+" navigation
  SettingsUITests.swift           # Settings navigation
  COILUITestsLaunchTests.swift    # Launch screenshot test

ios/PT-Helper/
  COIL.xcodeproj                  # Xcode 16 project (PBXFileSystemSynchronizedRootGroup — new files auto-discovered)
  UnitPlan / SmokePlan / FullPlan / PreReleasePlan .xctestplan
  vendor/, build/                 # gitignored local directories (fastlane gems, build products)
```
